# frozen_string_literal: true

require "io/wait"
require_relative "baseline"
require_relative "harness/selected_target"
require_relative "program_build"
require_relative "workers"
require_relative "../../lib/zr/native/resident"

module Zr
  module Test
    # The program tests: `bin/test test/programs`. Each test is a plain
    # Ruby file with ruby's output next to it (`Case`). zr builds it, runs
    # the binary, and compares stdout, stderr and the exit status with
    # ruby's, byte for byte. It uses no test framework.
    #
    # Forked workers share the tests. Each worker is a fork of this
    # process, which has loaded zr and the runtime's caches, so a worker
    # builds a test in process and loads nothing again. A worker that
    # grows more than `Workers::RECYCLE_MB` is replaced, and a test that
    # takes more than `Workers::DEADLINE` seconds stops its worker and
    # fails.
    #
    # A test prints `.` when it passes, `F` when its output is different,
    # `E` when zr does not build or run it, and `S` when this machine
    # cannot run it or the target's baseline allows its failure. The run
    # then prints each failure with a diff, and a count.
    class Programs
      ROOT = File.expand_path("../programs", __dir__)

      # The outcome of one test. `kind` is :pass, :fail, :error or :skip.
      Result = Data.define(:rel, :kind, :detail, :seconds)

      MARK = { pass: ".", fail: "F", error: "E", skip: "S" }.freeze

      # Runs the tests below `paths` (directories or programs) whose
      # programs run in `root`, and returns true when none failed.
      def self.run(paths, root: ROOT, target: Harness.selected_target, out: $stdout, host: false)
        tests = paths.flat_map { |path| Case.under(path, root) }.uniq
        allowed = if host then Baseline.host
                  elsif root == ROOT then Baseline.for(target)
                  else Baseline.corpus(root, target)
                  end
        new(tests, target, allowed, out, host: host).run
      end

      # With `host`, each program runs on CRuby over the kernel
      # (`HostProgram`), and not as a binary.
      def initialize(tests, target, allowed, out, host: false)
        @tests = tests
        @runner = Harness::Runner.new(ProgramBuild::ROOT, target)
        @allowed = allowed
        @out = out
        @host = host
      end

      def run
        @out.puts "#{@tests.size} program test(s), #{Workers.size} worker(s) for #{@host ? "the host (CRuby)" : @runner.target.triple}"
        results = Pool.new(Workers.size) { |test| check(test) }.map(@tests) do |result|
          @out.print MARK.fetch(result.kind)
          @out.flush
        end
        report(results)
        results.none? { |result| %i[fail error].include?(result.kind) }
      end

      # The result of one test, in a worker.
      def check(test)
        began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        kind, detail = unmet(test) ? [:skip, unmet(test)] : outcome(test)
        kind, detail = baselined(test, kind, detail) if @allowed.key?(test.rel)
        Result.new(test.rel, kind, detail, Process.clock_gettime(Process::CLOCK_MONOTONIC) - began)
      rescue StandardError, ScriptError => e
        Result.new(test.rel, :error, "#{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}", 0)
      end

      # Why this machine cannot run `test`, or nil.
      def unmet(test)
        return @runner.refusal if @runner.refusal

        platforms, needs = test.needs.partition { |name| Harness::Runner::PLATFORMS.value?(name) }
        return "runs only on #{platforms.join(", ")}" unless platforms.empty? || platforms.include?(@runner.platform)

        need = needs.find { |name| !Harness::Needs.met?(name, @runner.platform) }
        "needs #{need}" if need
      end

      def outcome(test)
        got = @host ? HostProgram.answer(test, @runner) : ProgramBuild.answer(test, @runner)
        return [:error, got.join(": ")] if got.is_a?(Array)

        want = ProgramRun.expected(test, @runner.platform)
        same = %i[stdout stderr code signal].all? { |part| want.public_send(part) == got.public_send(part) }
        same ? [:pass, nil] : [:fail, Diff.of(want, got)]
      end

      # The target's baseline allows `test` to fail: a failure is a skip
      # with the reason, and a pass fails, so the baseline stays current.
      def baselined(test, kind, detail)
        triple = @host ? "host" : @runner.target.triple
        case kind
        when :pass then [:fail, "this now passes: take it off test/baselines/#{triple}.txt"]
        when :skip then [kind, detail]
        else [:skip, "the #{triple} baseline allows this: #{@allowed.fetch(test.rel)}"]
        end
      end

      def report(results)
        @out.puts
        bad = results.select { |result| %i[fail error].include?(result.kind) }
        bad.each do |result|
          @out.puts "\n#{result.kind == :fail ? "FAIL" : "ERROR"}: #{result.rel}"
          @out.puts result.detail.to_s.lines.first(40).join
        end
        counts = results.map(&:kind).tally
        @out.puts format("\n%d tests: %d passed, %d failed, %d errors, %d skipped",
                         results.size, *%i[pass fail error skip].map { |kind| counts.fetch(kind, 0) })
      end

      # A diff of two answers, part by part: unified lines for stdout and
      # stderr, and the exit status when it differs.
      module Diff
        module_function

        def of(want, got)
          out = []
          %i[stderr stdout].each do |part|
            a = want.public_send(part).b
            b = got.public_send(part).b
            next if a == b

            out << "--- expected #{part}\n+++ actual #{part}\n#{lines(a.lines, b.lines).join}"
          end
          out << "status: expected #{want.status}, actual #{got.status}" if want.status != got.status
          out.join("\n")
        end

        # The lines of `a` and `b`, each marked ` `, `-` or `+`, from their
        # longest common subsequence. Outputs of more than 2,000 lines
        # compare only up to the first difference, with its context.
        def lines(a, b)
          return head(a, b) if a.size * b.size > 4_000_000

          lcs = Array.new(a.size + 1) { Array.new(b.size + 1, 0) }
          (a.size - 1).downto(0) do |i|
            (b.size - 1).downto(0) do |j|
              lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : [lcs[i + 1][j], lcs[i][j + 1]].max
            end
          end
          i = j = 0
          out = []
          while i < a.size || j < b.size
            if i < a.size && j < b.size && a[i] == b[j]
              out << " #{a[i]}"
              i += 1
              j += 1
            elsif i < a.size && (j == b.size || lcs[i + 1][j] >= lcs[i][j + 1])
              out << "-#{a[i]}"
              i += 1
            else
              out << "+#{b[j]}"
              j += 1
            end
          end
          out.map { |line| line.end_with?("\n") ? line : "#{line}\n\\ no newline at end\n" }
        end

        def head(a, b)
          n = a.zip(b).index { |x, y| x != y } || [a.size, b.size].min
          [*a[[n - 3, 0].max...n].map { |line| " #{line}" }, *(("-#{a[n]}") if a[n]), *(("+#{b[n]}") if b[n]),
           "... (#{a.size} expected lines, #{b.size} actual lines)\n"]
        end
      end

      # Forked workers that each take one test at a time. `work` runs in
      # the worker; `map` yields each result as it arrives and returns all
      # of them in the order of the tests.
      class Pool
        def initialize(size, &work)
          @size = size
          @work = work
        end

        def map(items)
          results = Array.new(items.size)
          pending = (0...items.size).to_a
          workers = []
          $stdout.flush
          Process.warmup
          until pending.empty? && workers.all?(&:idle?)
            workers.reject!(&:dead?)
            (@size - workers.size).times { workers << Worker.new(items, @work) } unless pending.empty?
            workers.each { |worker| worker.give(pending.shift) if worker.idle? && !pending.empty? }
            busy = workers.reject(&:idle?)
            break if busy.empty? && pending.empty?

            ready = IO.select(busy.map(&:back), nil, nil, 1)&.first || []
            busy.each do |worker|
              result = if ready.include?(worker.back) then worker.take
                       elsif worker.late? then worker.stop("ran past #{Workers::DEADLINE}s")
                       end
              next unless result

              results[worker.last] = result
              yield result
            end
          end
          workers.each(&:close)
          results
        end

        # One forked process, its two pipes, and the test it runs now.
        class Worker
          attr_reader :back, :last

          def initialize(items, work)
            @items = items
            @work = work
            jobs_r, @jobs = IO.pipe
            @back, back_w = IO.pipe
            $stdout.flush
            @pid = Process.fork do
              Process.setpgid(0, 0)
              Signal.trap("TERM") do
                Harness::Child.stop_all
                exit!(1)
              end
              @jobs.close
              @back.close
              serve(jobs_r, back_w)
            end
            jobs_r.close
            back_w.close
            @now = nil
            @dead = false
          end

          def serve(jobs, back)
            back.sync = true
            start = Native::Resident.of(Process.pid) || 0
            loop do
              at = Marshal.load(jobs)
              result = @work.call(@items.fetch(at))
              grown = (Native::Resident.of(Process.pid) || 0) - start
              Marshal.dump([result, grown], back)
            end
          rescue IOError
            nil
          ensure
            exit!(0)
          end

          def idle? = @now.nil? && !@dead
          def dead? = @dead

          def give(at)
            @now = at
            @since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            Marshal.dump(at, @jobs)
            @jobs.flush
          end

          # The result that the worker sent, or an error when it died.
          def take
            @last = @now
            result, grown = Marshal.load(@back)
            @now = nil
            close if grown > Workers::RECYCLE_MB
            result
          rescue EOFError, TypeError, ArgumentError
            stop("the worker died")
          end

          def late? = !Workers::DEADLINE.zero? && Process.clock_gettime(Process::CLOCK_MONOTONIC) - @since > Workers::DEADLINE

          # Stops the worker and gives an error for its test.
          def stop(why)
            @last = @now
            test = @items.fetch(@now)
            close
            Result.new(test.rel, :error, why, 0)
          end

          def close
            return if @dead

            @dead = true
            @now = nil
            [@jobs, @back].each { |io| io.close unless io.closed? }
            begin
              Process.kill("TERM", -@pid)
            rescue Errno::ESRCH, Errno::EPERM
              nil
            end
            Process.wait(@pid)
          rescue Errno::ECHILD
            nil
          end
        end
      end
    end
  end
end
