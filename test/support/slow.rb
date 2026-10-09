# frozen_string_literal: true

require "minitest"
require_relative "../../lib/zr/config"

module Zr
  module Test
    # Reports where the time of a run went: the slowest tests by name,
    # and, for examples that build a program, the time of each build
    # part, added up by directory.
    #
    # `SLOW=1` also makes minitest-reporters show the slowest *suites*.
    # That gives the file, not the test. Most of the time of a tier is in
    # a few tests (for example, one that lowers the whole runtime), and
    # this report gives their names. The worker that runs a test measures
    # its time and returns it in the result, so the time does not include
    # the pool.
    #
    # `SLOW=30` prints 30 tests. `SLOW=1` prints 20. When `SLOW` is not
    # set, this report is off.
    module Slow
      # The metadata key for the build part times of an example, in seconds.
      KEY = :zr_phases
      PARTS = %i[lower link run].freeze
      DEFAULT = 20

      # `SLOW=1` reports the slowest examples; `SLOW=<n>` reports <n>.
      def self.asked? = Config.flag?("SLOW")

      def self.count = ENV["SLOW"].to_i.then { |n| n > 1 ? n : DEFAULT }

      def self.minitest_plugin_init(options)
        Minitest.reporter << Reporter.new(options[:io], count) if asked?
      end

      # Runs the block and adds its time to `row[part]`. Each example has
      # its own `row`, so an example that builds twice counts both builds.
      # When `row` is nil (no report), it only runs the block.
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

        def to_s = format("%8d %8.1f %8.1f %8.1f %8.1f", examples, *PARTS.map { |part| parts[part] }, whole)
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
          @tests << [result.time, "#{result.klass}##{result.name}"]
          parts = result.metadata[KEY] if result.metadata?
          @spent[directory(result)].add(result.time, parts) if parts
        end

        def report
          return if @tests.empty?

          report_tests
          report_parts unless @spent.empty?
        end

        private

        # `@tests` holds `[seconds, name]` pairs.
        def report_tests
          slowest = @tests.max_by(@count, &:first)
          @io.puts format("\nThe %d slowest of %d tests, %.1f s of %.1f s in all:",
                          slowest.size, @tests.size, slowest.sum(&:first), @tests.sum(&:first))
          slowest.each { |seconds, name| @io.puts format("%8.2f s  %s", seconds, name) }
        end

        def report_parts
          rows = @spent.sort_by { |_, spent| -spent.whole }
          @io.puts "\nWhat the examples that build a program spent, in seconds:"
          @io.puts format("%-36s %8s %8s %8s %8s %8s", "directory", "examples", *PARTS, "whole")
          rows.first(@count).each { |name, spent| @io.puts format("%-36s %s", name, spent) }
          @io.puts format("%-36s %s", "all #{rows.size} directories", rows.sum(Spent.zero, &:last))
        end

        # Returns the path of the test file from `test/`, for example
        # `test/unit/cache_test.rb`.
        def directory(result)
          file = result.source_location.first.to_s
          file[%r{test/.*\z}] || file
        end
      end
    end
  end
end

Minitest.register_plugin(Zr::Test::Slow)
