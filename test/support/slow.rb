# frozen_string_literal: true

require "minitest"

module Ze0
  module Test
    # Where a run's time went: the slowest tests by name, and for the
    # examples that build a program, what each part of the build cost,
    # added up by directory.
    #
    # `SLOW=1` already asks minitest-reporters for the slowest *suites*,
    # which says which file to look in and not which test. A tier's
    # time is a handful of tests -- one that lowers the whole runtime,
    # one that reads five thousand fixtures -- and this names them. A
    # test's time is taken in the worker that ran it and comes back in
    # its result, so the numbers are the test's own and not the pool's.
    #
    # `ZE0_SLOW=30` prints thirty; `ZE0_SLOW=1`, or `SLOW=1`, prints
    # twenty. Unset, the run reports as it always did.
    module Slow
      # The key an example leaves its build's parts under, in seconds:
      # `{ lower:, link:, run: }`.
      KEY = :ze0_phases
      PARTS = %i[lower link run].freeze

      def self.asked = ENV["ZE0_SLOW"] || ENV["SLOW"]

      def self.count
        n = ENV["ZE0_SLOW"].to_i
        n > 1 ? n : 20
      end

      def self.minitest_plugin_init(options)
        Minitest.reporter << Reporter.new(options[:io], count) if asked
      end

      # Runs `part` and adds what it took to `into`, which is the
      # example's own row: an example that builds twice counts both.
      def self.clock(into, part)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
      ensure
        into[part] = into.fetch(part, 0.0) + (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) if into
      end

      class Reporter < Minitest::AbstractReporter
        def initialize(io, count)
          super()
          @io = io
          @count = count
          @tests = []
          @parts = Hash.new { |h, dir| h[dir] = Hash.new(0.0) }
        end

        def record(result)
          file = result.source_location&.first.to_s
          @tests << [result.time, "#{result.klass}##{result.name}", file]
          row = result.metadata[KEY] if result.metadata?
          return unless row

          into = @parts[directory(file)]
          into[:examples] += 1
          into[:whole] += result.time
          PARTS.each { |part| into[part] += row.fetch(part, 0.0) }
        end

        def report
          return if @tests.empty?

          @io.puts format("\nThe %d slowest of %d tests, %.1f s of %.1f s in all:", [@count, @tests.size].min, @tests.size,
                          slowest.sum(&:first), @tests.sum(&:first))
          slowest.each { |time, name, _| @io.puts format("%8.2f s  %s", time, name) }
          parts
        end

        private

        def slowest = @slowest ||= @tests.max_by(@count, &:first)

        # `test/spec/core/string`, from a file under it; a file's own
        # path where it is not that deep.
        def directory(file)
          file[%r{test/(?:spec|e2e)/[^/]+/[^/]+}] || file[%r{test/.*\z}] || file
        end

        def parts
          return if @parts.empty?

          @io.puts "\nWhat the examples that build a program spent, in seconds:"
          @io.puts format("%-36s %8s %8s %8s %8s %8s", "directory", "examples", "lower", "link", "run", "whole")
          rows = @parts.sort_by { |_, row| -row[:whole] }
          rows.first(@count).each { |dir, row| @io.puts line(dir, row) }
          @io.puts line("all #{rows.size} directories", rows.map(&:last).each_with_object(Hash.new(0.0)) do |row, sum|
            row.each { |part, n| sum[part] += n }
          end)
        end

        def line(name, row)
          format("%-36s %8d %8.1f %8.1f %8.1f %8.1f", name, row[:examples], row[:lower], row[:link], row[:run], row[:whole])
        end
      end
    end
  end
end

Minitest.register_plugin(Ze0::Test::Slow)
