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
      # The key an example leaves its build's parts under, in seconds.
      KEY = :ze0_phases
      PARTS = %i[lower link run].freeze
      DEFAULT = 20

      def self.asked? = ENV.key?("ZE0_SLOW") || ENV.key?("SLOW")

      def self.count = ENV["ZE0_SLOW"].to_i.then { |n| n > 1 ? n : DEFAULT }

      def self.minitest_plugin_init(options)
        Minitest.reporter << Reporter.new(options[:io], count) if asked?
      end

      # Runs the block and adds what it took to `row[part]`. `row` is
      # the example's own, so an example that builds twice counts both;
      # nil, where nobody asked, only runs the block.
      def self.clock(row, part)
        return yield unless row

        started = now
        begin
          yield
        ensure
          row[part] = row.fetch(part, 0.0) + (now - started)
        end
      end

      def self.now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Timed = Data.define(:seconds, :name)

      # What one directory's examples spent, part by part.
      Spent = Struct.new(:examples, :whole, *PARTS) do
        def self.zero = new(0, 0.0, *PARTS.map { 0.0 })

        def add(seconds, parts)
          self.examples += 1
          self.whole += seconds
          PARTS.each { |part| self[part] += parts.fetch(part, 0.0) }
        end

        def +(other) = self.class.new(*to_a.zip(other.to_a).map(&:sum))

        def to_s = format("%8d %8.1f %8.1f %8.1f %8.1f", examples, *PARTS.map { |part| self[part] }, whole)
      end

      class Reporter < Minitest::AbstractReporter
        def initialize(io, count)
          super()
          @io = io
          @count = count
          @tests = []
          @spent = Hash.new { |h, directory| h[directory] = Spent.zero }
        end

        def record(result)
          @tests << Timed.new(result.time, "#{result.klass}##{result.name}")
          parts = result.metadata[KEY] if result.metadata?
          @spent[directory(result)].add(result.time, parts) if parts
        end

        def report
          return if @tests.empty?

          report_tests
          report_parts unless @spent.empty?
        end

        private

        def report_tests
          slowest = @tests.max_by(@count, &:seconds)
          @io.puts format("\nThe %d slowest of %d tests, %.1f s of %.1f s in all:",
                          slowest.size, @tests.size, slowest.sum(&:seconds), @tests.sum(&:seconds))
          slowest.each { |test| @io.puts format("%8.2f s  %s", test.seconds, test.name) }
        end

        def report_parts
          rows = @spent.sort_by { |_, spent| -spent.whole }
          @io.puts "\nWhat the examples that build a program spent, in seconds:"
          @io.puts format("%-36s %8s %8s %8s %8s %8s", "directory", "examples", *PARTS, "whole")
          rows.first(@count).each { |name, spent| @io.puts format("%-36s %s", name, spent) }
          @io.puts format("%-36s %s", "all #{rows.size} directories", rows.sum(Spent.zero, &:last))
        end

        # `test/spec/core/string`, from a file under it; the file's own
        # path where it is not that deep.
        def directory(result)
          file = result.source_location.first.to_s
          file[%r{test/(?:spec|e2e)/[^/]+/[^/]+}] || file[%r{test/.*\z}] || file
        end
      end
    end
  end
end

Minitest.register_plugin(Ze0::Test::Slow)
