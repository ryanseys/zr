# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require "tmpdir"
require "timeout"
require_relative "case"

module Ze0
  module Harness
    # `ze0 test`: does ze0 answer what ruby answered?
    #
    # One program costs one ze0 compile, one native build and one run. On
    # the `zr` road (the default) `ze0 zr build` does all three in one
    # child; on the `legacy` road the old text lowering runs and nothing
    # links. A program lands in one bucket, and only the last three are
    # defects:
    #
    #   skipped    no recording, or a directive that opts the program out
    #   refused    ze0 named a form outside its subset, at its line
    #   backend    the compile produced no binary (or no native road exists yet)
    #   matched    the binary said what ruby said
    #   diverged   the binary said something else
    #   crashed    the binary died on a signal ruby did not
    #   timeout    the binary ran past the limit
    #
    # Run on demand: a corpus-wide sweep is minutes of real links, and the
    # buckets move with every feature. It is never a corpus census in one
    # process; every compile is its own ruby.
    class Sweep
      # The directories ruby recorded and ze0 is held to, and how deep a
      # program sits under each.
      SUITES = {
        "lang" => 2, "core" => 2, "stdlib" => 2, "compiler" => 2,
        "aot" => 1, "bench" => 1, "milestones" => 1, "ze0" => 1, "gaps" => 1
      }.freeze

      # Long enough for the slowest corpus program, short enough that a
      # miscompile that loops does not stall the sweep.
      LIMIT = 60

      Row = Struct.new(:rb, :bucket, :why)

      # `road`: "zr" (a binary through `ze0 zr build`) or "legacy" (the
      # text lowering, which nothing links).
      # `gc`: "plain", or "stress" for a collection at every allocation.
      def initialize(root, show: 10, jobs: nil, road: "zr", gc: "plain")
        @root = root
        @show = show
        @jobs = jobs || Etc.nprocessors
        @road = road
        @gc = gc
      end

      # Every recorded program whose path contains one of `filters` (or all
      # of them), in a stable order.
      def select(filters, all: false)
        out = []
        SUITES.each do |suite, depth|
          dir = File.join(@root, "test", suite)
          pattern = depth == 1 ? "*.rb" : "*/*.rb"
          Dir[File.join(dir, pattern)].sort.each do |rb|
            rel = rb.delete_prefix("#{@root}/")
            name = "#{suite}::#{rel.delete_prefix("test/#{suite}/")}"
            out << rb if all || filters.any? { |f| name.include?(f) || rel.include?(f.delete_prefix("./")) }
          end
        end
        out
      end

      def run(cases)
        queue = Queue.new
        cases.each { |rb| queue << rb }
        rows = Queue.new
        workers = Array.new([@jobs, cases.size].min) do |w|
          Thread.new do
            Dir.mktmpdir("ze0-test-#{w}-") do |work|
              until queue.empty?
                rb = queue.pop(true) rescue break
                rows << begin
                  one(rb, work)
                rescue StandardError => e
                  Row.new(rb, :backend, "#{e.class}: #{e.message}")
                end
              end
            end
          end
        end
        workers.each(&:join)
        out = []
        out << rows.pop until rows.empty?
        out.sort_by(&:rb)
      end

      # Compile, build, run, compare.
      def one(rb, work)
        kase = Case.read(rb)
        return Row.new(rb, :skipped, "no recording") unless kase.recorded?
        return Row.new(rb, :skipped, "only #{kase.directives.only}") if kase.directives.only && kase.directives.only != "macos"
        return Row.new(rb, :skipped, "needs the compiler in process") if kase.directives.backend

        cwd = File.join(@root, "test")
        rel = rb.delete_prefix("#{cwd}/")
        bin = File.join(work, "p")
        File.delete(bin) if File.exist?(bin)

        if @road == "zr"
          out = bounded([RbConfig.ruby, File.join(@root, "bin/ze0"), "zr", "build", rel, "-o", bin], cwd, nil)
          return Row.new(rb, :refused, first_line(out).sub(/\Aze0: /, "")) if out.code == 3
          return Row.new(rb, :backend, "the build ran past #{LIMIT}s") if out.code == :timeout
          return Row.new(rb, :backend, first_line(out)) unless out.code == 0
        else
          clif = File.join(work, "p.clif")
          out = bounded([RbConfig.ruby, File.join(@root, "ze0.rb"), rel, "-o", clif], cwd, nil)
          return Row.new(rb, :refused, first_line(out)) unless out.code == 0

          return Row.new(rb, :backend, "the legacy road links nothing")
        end

        stdin = kase.directives.stdin && File.binread(File.join(File.dirname(rb), kase.directives.stdin))
        env = kase.directives.env.merge(kase.directives.zeo_env)
        env["ZR_GC_STRESS"] = "1" if @gc == "stress"
        out = bounded([bin, *kase.directives.args], cwd, stdin, env)
        return Row.new(rb, :timeout, "ran past #{LIMIT}s") if out.code == :timeout

        actual = Normalize.answer(out, rb, cwd)
        expected = Normalize.answer(kase.expected, rb, cwd)
        return Row.new(rb, :matched, nil) if actual == expected
        # A stop the program did not rescue: ruby's report of the
        # NotImplementedError or LoadError it raised, or a kernel stop.
        if (stop = actual.stderr[/^(?:ze0: |.*?:in '[^']*': )?(.* is not implemented yet)(?: \((?:NotImplementedError|LoadError)\))?$/, 1])
          return Row.new(rb, :refused, "#{File.basename(rb)}: run time: #{stop}")
        end
        return Row.new(rb, :crashed, "signal #{actual.signal}") if actual.signal && !expected.signal

        Row.new(rb, :diverged, diff(expected, actual))
      end

      # A child with both streams captured and a wall-clock bound.
      def bounded(argv, cwd, stdin, env = {})
        env = { "RUBYOPT" => nil, "RUBYLIB" => nil }.merge(env)
        out_r, out_w = IO.pipe
        err_r, err_w = IO.pipe
        in_r, in_w = IO.pipe
        pid = Process.spawn(env, *argv, chdir: cwd, in: in_r, out: out_w, err: err_w, pgroup: true)
        [out_w, err_w, in_r].each(&:close)
        writer = Thread.new do
          in_w.binmode
          in_w.write(stdin) if stdin
        rescue Errno::EPIPE
          nil
        ensure
          in_w.close
        end
        reader = [out_r, err_r].map { |io| Thread.new { io.binmode; io.read } }
        status = nil
        begin
          Timeout.timeout(LIMIT) { _, status = Process.wait2(pid) }
        rescue Timeout::Error
          # The whole group, so a child of the program does not keep the
          # pipes open and stall the read below.
          Process.kill("KILL", -pid) rescue nil
          Process.wait(pid) rescue nil
        end
        writer.join
        stdout, stderr = reader.map(&:value)
        return Answer.new(stdout, stderr, :timeout, nil) if status.nil?

        Answer.new(stdout, stderr, status.exitstatus || -1, status.termsig)
      end

      def first_line(out)
        text = out.stderr.empty? ? out.stdout : out.stderr
        text.lines.first&.strip || "(no message)"
      end

      # Where the two answers part, per stream: the first line that differs,
      # or the counts when one side simply stops.
      def diff(expected, actual)
        out = []
        %i[stdout stderr].each do |what|
          want, got = expected[what].lines, actual[what].lines
          next if want == got

          n = want.zip(got).index { |a, b| a != b }
          out << if n && n < [want.size, got.size].min
                   "#{what}: want #{want[n].chomp.inspect}, got #{got[n].chomp.inspect}"
                 else
                   "#{what}: want #{want.size} line(s), got #{got.size} -- #{(want[got.size] || got[want.size]).to_s.chomp.inspect}"
                 end
        end
        out << "#{expected.status} vs #{actual.status}" if expected.status != actual.status
        out.empty? ? "identical text, unequal bytes" : out.join("\n           ")
      end

      # The report, and whether the sweep passed: every defect bucket empty.
      def report(rows, io = $stdout)
        by = rows.group_by(&:bucket)
        io.puts
        %i[matched refused backend skipped diverged crashed timeout].each do |b|
          io.puts format("%-9s %d", b, (by[b] || []).size)
        end
        shapes(by[:refused] || []).each { |what, n| io.puts format("  %4d  %s", n, what) }
        shown = 0
        %i[backend diverged crashed timeout].each do |b|
          (by[b] || []).each do |row|
            next if (shown += 1) > @show

            io.puts "  #{b} #{row.rb.delete_prefix("#{@root}/")}\n           #{row.why}"
          end
        end
        io.puts "  ... #{shown - @show} more (--show N)" if shown > @show
        io.puts "  every row: #{save(rows)}"
        %i[diverged crashed timeout].sum { |b| (by[b] || []).size }.zero?
      end

      # Every row but the matched ones, kept under tmp/ so a sweep's list
      # outlives its terminal.
      def save(rows)
        path = File.join(@root, "tmp", "sweep.txt")
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "w") do |f|
          rows.reject { |row| row.bucket == :matched }.each do |row|
            f.puts "#{row.bucket} #{row.rb.delete_prefix("#{@root}/")}\n    #{row.why}"
          end
        end
        path
      end

      # The refusals counted by SHAPE: the sentence names the gap.
      def shapes(refused)
        counts = Hash.new(0)
        refused.each do |row|
          why = row.why
          shape = (why[/: (?:line \d+|run time): (.*)\z/, 1] || why).delete_suffix(" is not in ze0's subset")
          counts[shape] += 1
        end
        counts.sort_by { |what, n| [-n, what] }
      end
    end
  end
end
