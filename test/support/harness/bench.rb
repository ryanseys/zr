# frozen_string_literal: true

require "benchmark"
require "etc"
require "fileutils"
require "rbconfig"
require "tmpdir"
require_relative "answer"
require_relative "child"
require_relative "runner"

module Ze0
  module Harness
    # `rake bench`: how long the binary ze0 built takes, beside the ruby
    # that recorded its answer.
    #
    # `benchmark/` holds whole programs the way `test/e2e` does -- a
    # `.rb` file, with what ruby answered in `<name>.out` beside it --
    # so what is here is the clock and the comparison columns, and
    # nothing that reads a program.
    #
    # **The answer is checked before any time is kept.** The speed of a
    # wrong answer means nothing, and a codegen step that trades an
    # answer for a time is the one thing the contract does not allow.
    #
    # Serial from end to end. The tiers run a worker per core because
    # they only ask what a program said; a time measured beside three
    # other compiles is not a time.
    class Bench
      # Long enough for the slowest program, and short enough that one
      # that loops does not hold the suite.
      LIMIT = 300

      # Five runs and the middle one: enough that one scheduling
      # accident is not the answer, few enough that the suite is minutes.
      # `bm_startup` prints one line: its row is the floor every other
      # row stands on, the process's start-up, and reads apart from it.
      RUNS = 5

      # Where a report goes. A run of the whole bank is written under
      # `benchmark/results/` as `<stamp>-<revision>.txt` -- when it was
      # taken, in UTC, so the files list in order, and the commit it
      # measured -- and committed with the code, so a later run reads
      # against it by hash; a run of some rows goes under `tmp`, since
      # a partial report says nothing about the rest.
      RESULTS = "benchmark/results"
      SCRATCH = "tmp/bench"
      LATEST = "latest.txt"

      # `build` is the compile, in seconds; the three others are the
      # program, each a `Benchmark::Tms` of the median run: its wall
      # clock in `real`, and the child's own user and system time as
      # `utime` and `stime`. A row with no time carries `why` instead.
      class Row
        attr_reader :rb, :bucket, :why, :build, :ze0, :ruby, :yjit

        def initialize(rb, bucket, why = nil, build: nil, ze0: nil, ruby: nil, yjit: nil)
          @rb = rb
          @bucket = bucket
          @why = why
          @build = build
          @ze0 = ze0
          @ruby = ruby
          @yjit = yjit
        end

        def name = File.basename(rb, ".rb")
        def timed? = bucket == :timed

        # The CPU the binary spent, apart from the wall clock: what the
        # program cost, with the machine's other work left out of it.
        def cpu = ze0.total

        # ze0's wall clock over `other`'s, a Tms or nil.
        def against(other) = timed? && other && other.real.positive? ? ze0.real / other.real : nil
      end

      def initialize(root, runs: RUNS, show: 10, target: Target.default)
        @root = root
        @runs = runs
        @show = show
        @runner = Runner.new(root, target, compiler: "cranelift")
      end

      # Every program under `benchmark/`, or the ones a filter names.
      def matching(filters)
        rows = Dir[File.join(@root, "benchmark/*.rb")].sort
        @whole = filters.empty?
        return rows if @whole

        rows.select { |rb| filters.any? { |f| File.basename(rb).include?(f) } }
      end

      # One child, bounded in time, and in memory where `megabytes` is
      # given. A timed run gives none: the sampler is a `ps` forked five
      # times a second, and its time would be read as the program's.
      def bounded(argv, cwd, stdin, megabytes, env)
        Child.run(argv, cwd: cwd, stdin: stdin, env: env, seconds: LIMIT, megabytes: megabytes).first
      end

      def run(cases, io = $stdout)
        io.sync = true
        Dir.mktmpdir("ze0-bench-") do |work|
          cases.map.with_index do |rb, n|
            io.print format("[%d/%d] %s ... ", n + 1, cases.size, File.basename(rb, ".rb"))
            row = one(rb, work)
            io.puts row.timed? ? format("%.3fs", row.ze0.real) : "#{row.bucket}: #{row.why}"
            row
          end
        end
      end

      # Build, check the answer, then time the three of them.
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
        got, wrong = medians("ze0", argv, cwd, nil, run_env, rb, want)
        return Row.new(rb, :diverged, wrong) if wrong

        plain, = medians("ruby", [RbConfig.ruby, rel], cwd, nil, {}, rb, nil)
        jit, = medians("yjit", [RbConfig.ruby, "--yjit", rel], cwd, nil, {}, rb, nil)
        Row.new(rb, :timed, build: build.real, ze0: got, ruby: plain, yjit: jit)
      end

      # The run at the middle of `@runs` wall clocks, as a Tms, and what
      # the first run of the binary got wrong when `want` is given. A
      # later run is not checked again: a program whose answer depends
      # on the run is a defect the spec tier is there to find, not
      # something to spend a comparison on.
      def medians(label, argv, cwd, stdin, env, rb, want)
        times = []
        @runs.times do |n|
          took, out = clocked(label) { bounded(argv, cwd, stdin, nil, env) }
          return [nil, "ran past #{LIMIT}s"] if out.code == :timeout

          if n.zero? && want
            got = Normalize.answer(out, rb, cwd)
            return [nil, want.apart_from(got)] if got != want
          elsif want.nil? && out.code != 0
            # ruby could not run it -- an old `--yjit`, a gem it wants.
            # The column stays empty and the row keeps its ze0 time.
            return [nil, nil]
          end
          times << took
        end
        [times.sort_by(&:real)[@runs / 2], nil]
      end

      # The block's answer and what it took, as a `Benchmark::Tms` of
      # the child's own: `Benchmark.measure` reads the user and system
      # time of the children the block waited for -- the one child it
      # ran, as nothing else forks meanwhile -- and the wall clock, and
      # the Tms kept has those as its `utime`, `stime` and `real`, so
      # that it prints and adds as any Tms does.
      def clocked(label)
        answer = nil
        took = Benchmark.measure { answer = yield }
        [Benchmark::Tms.new(took.cutime, took.cstime, 0.0, 0.0, took.real, label), answer]
      end

      def first_line(out)
        text = out.stderr.empty? ? out.stdout : out.stderr
        (text.lines.first&.strip || "(no message)").sub(/\Aze0: /, "")
      end

      # The table, the two geometric means, and whether every program
      # answered. A slow row is a result; a wrong row is a failure.
      def report(rows, io = $stdout)
        io.puts
        io.puts format("%-26s %8s %8s %8s %8s %8s %9s %9s", "program", "build", "ze0", "cpu", "ruby", "yjit", "vs ruby", "vs yjit")
        rows.each { |r| io.puts line(r) }
        timed = rows.select(&:timed?)
        io.puts
        io.puts format("%d timed, %d not", timed.size, rows.size - timed.size)
        %i[ruby yjit].each do |what|
          ratios = timed.filter_map { |r| r.against(r.public_send(what)) }
          next if ratios.empty?

          io.puts format("ze0 is %.2fx of %s, geometric mean over %d program(s)", geomean(ratios), what, ratios.size)
        end
        io.puts "  wrote #{save(rows)}"
        rows.none? { |r| %i[diverged backend].include?(r.bucket) }
      end

      def line(row)
        return format("%-26s %8.1f %8s %8s %8s %8s %9s %9s", row.name, row.build || 0, row.bucket, "", "", "", "", "") unless row.timed?

        format("%-26s %8.1f %8.3f %8.3f %8s %8s %9s %9s", row.name, row.build, row.ze0.real, row.cpu,
               seconds(row.ruby), seconds(row.yjit), times(row.against(row.ruby)), times(row.against(row.yjit)))
      end

      # A Tms's wall clock, or a dash for the column ruby left empty.
      def seconds(t) = t ? format("%.3f", t.real) : "-"
      def times(r) = r ? format("%.2fx", r) : "-"

      # The geometric mean, because these are ratios: the arithmetic one
      # would let a single slow program speak for the suite.
      def geomean(values) = Math.exp(values.sum { |v| Math.log(v) } / values.size)

      # The report as the benchmark gem prints one -- `Benchmark::CAPTION`
      # over a `Tms#format` line a runner, under the program's name --
      # at `benchmark/results/<stamp>-<revision>.txt` for the whole bank
      # (with `-dirty` where the tree has changes the hash does not
      # name), or `tmp/bench/latest.txt` for some of it.
      def save(rows)
        taken = Time.now.utc
        path = @whole ? File.join(@root, RESULTS, "#{taken.strftime("%Y%m%d-%H%M")}-#{revision}.txt") : File.join(@root, SCRATCH, LATEST)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text(rows, taken))
        path
      end

      # The short hash of HEAD, `-dirty` when the tree differs from it
      # under `lib`, `rt` or `benchmark`, or `unknown` outside git.
      def revision
        rev = `git -C #{@root} rev-parse --short HEAD 2>/dev/null`.strip
        return "unknown" if rev.empty?

        changed = `git -C #{@root} status --porcelain -- lib rt benchmark 2>/dev/null`.lines.reject { |l| l.include?(RESULTS) }
        changed.empty? ? rev : "#{rev}-dirty"
      end

      # The reports under `benchmark/results/`, newest last: the name
      # starts with the stamp.
      def self.results(root) = Dir[File.join(root, RESULTS, "*.txt")].sort

      # The report a revision's hash names there, or nil.
      def self.result_of(root, rev) = Dir[File.join(root, RESULTS, "*-#{rev}.txt")].max

      LABEL = "%-8n"

      def text(rows, taken = Time.now.utc)
        lines = ["# ze0 bench, the median of #{@runs} run(s) at #{revision}, #{taken.strftime("%Y-%m-%d %H:%M UTC")}"]
        rows.each do |r|
          lines << ""
          unless r.timed?
            lines << "#{r.name}  #{r.bucket}: #{r.why}"
            next
          end

          lines << format("%s  built in %.1f s", r.name, r.build)
          lines << (" " * 8) + Benchmark::CAPTION.chomp
          %i[ze0 ruby yjit].each do |what|
            t = r.public_send(what) or next
            lines << t.format(LABEL + Benchmark::FORMAT).chomp
          end
        end
        "#{lines.join("\n")}\n"
      end

      # `{ "bm_fib" => 0.1438, ... }`: the wall clock of `label`'s line
      # under each program in a report `save` wrote.
      def self.reals(text, label = "ze0")
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
