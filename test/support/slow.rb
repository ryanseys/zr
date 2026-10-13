# frozen_string_literal: true

require "minitest"
require_relative "../../lib/zr/config"
require_relative "../../lib/zr/timing"
require_relative "timings"

module Zr
  module Test
    # Reports where the time of a run went: the slowest tests by name,
    # the groups (test files, and directories of program tests) that took
    # the most time in all, and, for examples that build a program, the
    # time of each build part, added up by directory. Most of the time of
    # a tier is in a few tests (for example, one that lowers the whole
    # runtime), and this report gives their names. The worker that runs a
    # test measures its time and returns it in the result, so the time
    # does not include the pool. Each run also keeps its times
    # (`Timings`), which `zr-dev test --slowest` reads later.
    #
    # A run of SMALL tests or more prints its DEFAULT slowest tests and
    # groups at the end. `SLOW=1` prints ASKED of each, and the build
    # parts, for a run of any size; `SLOW=30` prints 30; `SLOW=0` prints
    # nothing.
    module Slow
      # The metadata key for the build part times of an example, in seconds.
      KEY = :zr_phases
      PARTS = %i[lower link run].freeze
      DEFAULT = 10
      ASKED = 20
      SMALL = 20

      def self.asked? = Config.flag?("SLOW")

      def self.off? = ENV["SLOW"] == "0"

      def self.count = ENV["SLOW"].to_i.then { |n| n > 1 ? n : asked? ? ASKED : DEFAULT }

      def self.minitest_plugin_init(options)
        Minitest.reporter << Reporter.new(options[:io], count, always: asked?) unless off?
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

      def self.now = Timing.now

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

      # With `always`, the report prints for a run of any size, with the
      # build parts; without, only for a run of SMALL tests or more.
      class Reporter < Minitest::AbstractReporter
        def initialize(io, count, always: true)
          super()
          @io = io
          @count = count
          @always = always
          @rows = []
          @spent = Hash.new { |h, directory| h[directory] = Spent.zero }
        end

        def record(result)
          @rows << Timings.row(result, nil)
          parts = result.metadata[KEY] if result.metadata?
          @spent[directory(result)].add(result.time, parts) if parts
        end

        def report
          return if @rows.empty? || (!@always && @rows.size < SMALL)

          Timings.report(@rows, @count, @io)
          report_parts if @always && !@spent.empty?
        end

        private

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
