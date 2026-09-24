# frozen_string_literal: true

require "minitest"

module Zr
  module Test
    # Where a run stands, written to a file as it goes, so a tier left
    # running in the background can be looked in on: how many examples
    # of how many are done, how many have failed and which, the rate
    # and what is left at it, and the example answered last. `rake
    # test:progress` prints it. The file is written at most once a
    # second and once more at the end, and says so.
    module Progress
      PATH = File.expand_path("../../tmp/test-progress.txt", __dir__)
      EVERY = 1.0

      def self.minitest_plugin_init(options)
        Minitest.reporter << Reporter.new(options)
      end

      # The file's text, or nil where no run has written one.
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

        # The examples the run will hand out, as minitest filters them.
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

        # The helper that loaded the tier names it.
        def tier = $LOADED_FEATURES.any? { |f| f.end_with?("/spec_helper.rb") } ? "spec tier" : "unit/e2e tier"
      end
    end
  end
end

Minitest.register_plugin(Zr::Test::Progress)
