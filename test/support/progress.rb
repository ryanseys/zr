# frozen_string_literal: true

require "minitest"
require_relative "flag"
require_relative "history"
require_relative "run_files"
require_relative "../../lib/zr/timing"

module Zr
  module Test
    # What one run tells while it goes and at its end. `History` keeps
    # what lasts across runs.
    #
    # While it runs, PATH holds its status, so you can check a tier that
    # runs in the background: the examples done and the total, the
    # failures, the rate, the time left and the last example. The file
    # changes at most once a second, and once more at the end. Each
    # failure's full report goes to FAILURES and to the run's output as it
    # happens, so you can read a diff before the run ends, and a run that
    # stops early keeps every report until then. Both files are the run's
    # (RunFiles).
    #
    # At the end, it prints where the time went: the slowest tests by
    # name and the groups (test files, and directories of program tests)
    # that took the most time in all. A run of SMALL tests or more prints
    # its DEFAULT slowest. `SLOW=1` prints ASKED of each for a run of any
    # size, with the time of each part of the examples that build a
    # program (`clock`), added up by directory; `SLOW=30` prints 30;
    # `SLOW=0` prints nothing. The worker that runs a test measures its
    # time, so the time does not include the pool. Last, it counts the
    # passes that came from the result cache.
    module Progress
      PATH = RunFiles.path("progress.log")
      FAILURES = RunFiles.path("failures.log")
      EVERY = 1.0

      # The metadata key for the build part times of an example, in seconds.
      PARTS_KEY = :zr_phases
      PARTS = %i[lower link compile run].freeze
      DEFAULT = 10
      ASKED = 20
      SMALL = 20

      # Whether `SLOW` asks for the build parts.
      def self.parts? = Zr::Test.flag?("SLOW")

      # How many slowest tests and groups the end prints: 0 for none.
      def self.count
        return 0 if ENV["SLOW"] == "0"

        ENV["SLOW"].to_i.then { |n| n > 1 ? n : parts? ? ASKED : DEFAULT }
      end

      def self.minitest_plugin_init(options)
        Minitest.reporter << Reporter.new(options)
      end

      # Runs the block and adds its time to `row[part]`. Each example has
      # its own `row`, so an example that builds twice counts both builds.
      # When `row` is nil (no report), it only runs the block.
      def self.clock(row, part)
        return yield unless row

        started = Timing.now
        begin
          yield
        ensure
          row[part] = row.fetch(part, 0.0) + (Timing.now - started)
        end
      end

      # The time of the examples in one directory: the number of
      # examples, the total seconds, and the seconds for each part.
      class Spent
        attr_reader :examples, :whole, :parts

        def self.zero = new(0, 0.0, PARTS.to_h { |part| [part, 0.0] })

        def initialize(examples, whole, parts)
          @examples = examples
          @whole = whole
          @parts = parts
        end

        def add(seconds, spent)
          @examples += 1
          @whole += seconds
          PARTS.each { |part| @parts[part] += spent.fetch(part, 0.0) }
        end

        def +(other) = Spent.new(examples + other.examples, whole + other.whole, PARTS.to_h { |part| [part, parts[part] + other.parts[part]] })

        def to_s = format("%8d#{" %8.1f" * (PARTS.size + 1)}", examples, *PARTS.map { |part| parts[part] }, whole)
      end

      # `status` is the file of the run's status, or nil for none. With
      # `parts`, the end prints for a run of any size, with the build
      # parts; without, only for a run of SMALL tests or more.
      class Reporter < Minitest::AbstractReporter
        def initialize(options, status: PATH, count: Progress.count, parts: Progress.parts?)
          super()
          @options = options
          @io = options[:io]
          @status = status
          @count = count
          @parts = parts
          @done = 0
          @failed = []
          @skipped = 0
          @cached = 0
          @last = nil
          @written = 0.0
          @rows = []
          @spent = Hash.new { |h, directory| h[directory] = Spent.zero }
        end

        def start
          return unless @status

          @began = Timing.now
          @started_at = Time.now.strftime("%H:%M:%S")
          @total = counted
          %w[progress.log failures.log].each { |suffix| RunFiles.start(suffix) }
          File.write(FAILURES, "")
          write
        end

        def record(result)
          @done += 1
          @skipped += 1 if result.skipped?
          failed = !result.passed? && !result.skipped?
          if failed
            @failed << "#{result.klass}##{result.name}"
            log_failure(result)
          end
          @rows << History.row(result, nil)
          if result.metadata?
            @cached += 1 if result.metadata[:cached]
            spent = result.metadata[PARTS_KEY]
            @spent[History.group(result)].add(result.time, spent) if spent
          end
          @last = format("%s#%s (%.1f s)", result.klass, result.name, result.time)
          # A failure shows at once, whatever the time since the last write.
          write if @status && (failed || Timing.now - @written >= EVERY)
        end

        def report
          write(final: true) if @status
          slowest
          @io.puts "\n#{@cached} of the passes came from the result cache (ZR_TEST_FRESH=1 runs them)" if @cached.positive?
        end

        private

        # The number of examples that the run will start, after the
        # minitest filters.
        def counted = Minitest::Runnable.runnables.sum { |klass| klass.filter_runnable_methods(@options).size }

        def write(final: false)
          @written = Timing.now
          elapsed = @written - @began
          rate = elapsed.positive? ? @done / elapsed : 0.0
          left = rate.positive? && @total > @done ? (@total - @done) / rate : nil
          lines = [
            format("%s: pid %d, started %s", final ? "finished" : "running", Process.pid, @started_at),
            format("%d/%d examples (%d%%), %d failed, %d skipped", @done, @total, @total.zero? ? 100 : 100 * @done / @total, @failed.size, @skipped),
            format("%.1f/s, %s elapsed%s", rate, clock(elapsed), left ? ", ~#{clock(left)} left" : "")
          ]
          lines << "last: #{@last}" if @last
          lines << "failed so far:" << @failed.last(20).map { |name| "  #{name}" } unless @failed.empty?
          File.write(@status, "#{lines.join("\n")}\n")
        rescue SystemCallError
          nil
        end

        def clock(seconds) = format("%d:%02d", seconds / 60, seconds % 60)

        # The report has the test's location, and an error's backtrace.
        def log_failure(result)
          return unless @status

          report = "== #{result.klass}##{result.name}\n#{result}\n"
          @io.print "\n#{report}"
          @io.flush
          File.open(FAILURES, "a") { |file| file << report }
        rescue SystemCallError
          nil
        end

        def slowest
          return if @count.zero? || @rows.empty? || (!@parts && @rows.size < SMALL)

          History.report(@rows, @count, @io)
          spent_by_directory if @parts && !@spent.empty?
        end

        def spent_by_directory
          rows = @spent.sort_by { |_, spent| -spent.whole }
          @io.puts "\nWhat the examples that build a program spent, in seconds:"
          @io.puts format("%-36s %8s#{" %8s" * (PARTS.size + 1)}", "directory", "examples", *PARTS, "whole")
          rows.first(@count).each { |name, spent| @io.puts format("%-36s %s", name, spent) }
          @io.puts format("%-36s %s", "all #{rows.size} directories", rows.sum(Spent.zero, &:last))
        end
      end
    end
  end
end

Minitest.register_plugin(Zr::Test::Progress)
