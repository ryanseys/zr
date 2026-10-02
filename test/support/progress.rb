# frozen_string_literal: true

require "minitest"

module Zr
  module Test
    # Writes the status of a run to a file, so that you can check a tier
    # that runs in the background. The file gives the examples done and
    # the total, the failures, the rate, the time left and the last
    # example. `zr-dev progress` prints it. The reporter writes the
    # file at most once a second, and one more time at the end.
    module Progress
      PATH = File.expand_path("../../tmp/test-progress.txt", __dir__)
      EVERY = 1.0

      def self.minitest_plugin_init(options)
        Minitest.reporter << Reporter.new(options)
      end

      # Returns the text of the file, or nil when no run wrote it.
      def self.read = File.exist?(PATH) ? File.read(PATH) : nil

      class Reporter < Minitest::AbstractReporter
        def initialize(options)
          super()
          @options = options
          @done = 0
          @failed = []
          @skipped = 0
          @last = nil
          @written = 0.0
        end

        def start
          @began = now
          @started_at = Time.now.strftime("%H:%M:%S")
          @total = counted
          write
        end

        def record(result)
          @done += 1
          @skipped += 1 if result.skipped?
          @failed << "#{result.klass}##{result.name}" if !result.passed? && !result.skipped?
          @last = format("%s#%s (%.1f s)", result.klass, result.name, result.time)
          write if now - @written >= EVERY
        end

        def report
          write(final: true)
        end

        private

        def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # The number of examples that the run will start, after the
        # minitest filters.
        def counted = Minitest::Runnable.runnables.sum { |klass| klass.filter_runnable_methods(@options).size }

        def write(final: false)
          @written = now
          elapsed = @written - @began
          rate = elapsed.positive? ? @done / elapsed : 0.0
          left = rate.positive? && @total > @done ? (@total - @done) / rate : nil
          lines = [
            format("%s: %s, pid %d, started %s", final ? "finished" : "running", tier, Process.pid, @started_at),
            format("%d/%d examples (%d%%), %d failed, %d skipped", @done, @total, @total.zero? ? 100 : 100 * @done / @total, @failed.size, @skipped),
            format("%.1f/s, %s elapsed%s", rate, clock(elapsed), left ? ", ~#{clock(left)} left" : "")
          ]
          lines << "last: #{@last}" if @last
          lines << "failed so far:" << @failed.last(20).map { |name| "  #{name}" } unless @failed.empty?
          File.write(PATH, "#{lines.join("\n")}\n")
        rescue SystemCallError
          nil
        end

        def clock(seconds) = format("%d:%02d", seconds / 60, seconds % 60)

        def tier = "bin/minitest"
      end
    end
  end
end

Minitest.register_plugin(Zr::Test::Progress)
