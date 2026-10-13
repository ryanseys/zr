# frozen_string_literal: true

require "fileutils"
require "minitest"

module Zr
  module Test
    # The time of each test, kept across runs, so that you can find the
    # slow tests with no run of their own (`zr-dev test --slowest`). Each
    # line of TABLE is one test: its seconds, the date of the run, its group
    # (its test file, or a program test's directory below test/programs)
    # and its name (`Class#test_name`), separated by tabs, the slowest
    # first.
    #
    # A run writes each time to a journal of its own as the test ends, so a
    # run that is killed keeps the times so far. The end of the run adds
    # its journal to TABLE, and so does the start of a later run for a
    # journal whose run is gone. A test that ran again gets its new time; a
    # test that did not keeps its old one.
    module Timings
      ROOT = File.expand_path("../..", __dir__)
      DIR = File.join(ROOT, "tmp", "zr-dev-test")
      TABLE = File.join(DIR, "times.tsv")
      JOURNAL = /\Atimes-(\d+)\.tsv\z/

      Row = Struct.new(:seconds, :date, :group, :name)

      def self.minitest_plugin_init(_options)
        Minitest.reporter << Reporter.new
      end

      # `{ name => Row }` of the file at `path`, or none.
      def self.read(path = TABLE)
        return {} unless File.file?(path)

        File.foreach(path, chomp: true).each_with_object({}) do |line, rows|
          seconds, date, group, name = line.split("\t", 4)
          rows[name] = Row.new(Float(seconds), date, group, name) if name
        end
      end

      # Adds each journal in `dir` to the table there and removes it: the
      # journal of `mine` (a pid), and each one whose run has ended.
      def self.merge(dir = DIR, mine: nil)
        table = File.join(dir, File.basename(TABLE))
        journals = Dir.children(dir).filter_map do |name|
          pid = name[JOURNAL, 1]&.to_i
          File.join(dir, name) if pid && (pid == mine || !running?(pid))
        end
        return if journals.empty?

        rows = read(table)
        journals.sort_by { |path| File.mtime(path) }.each do |path|
          rows.merge!(read(path))
          File.delete(path)
        end
        write(rows.values, table)
      rescue SystemCallError
        nil
      end

      def self.running?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def self.write(rows, path)
        FileUtils.mkdir_p(File.dirname(path))
        part = "#{path}.#{Process.pid}"
        File.write(part, rows.sort_by { |row| [-row.seconds, row.name] }.map { |row| line(row) }.join)
        File.rename(part, path)
      end

      def self.line(row) = format("%.3f\t%s\t%s\t%s\n", row.seconds, row.date, row.group, row.name)

      # The group of a result: a program test's directory below
      # test/programs, or the test file below the root.
      def self.group(result)
        return File.join("test/programs", File.dirname(result.name.delete_prefix("test_"))) if result.klass == "ProgramsTest"

        path = result.source_location.first.to_s
        path.start_with?("#{ROOT}/") ? path.delete_prefix("#{ROOT}/") : path[%r{test/.*\z}] || path
      end

      def self.row(result, date) = Row.new(result.time, date, group(result), "#{result.klass}##{result.name}")

      # Prints the `count` slowest of `rows` and the `count` groups that
      # took the most time in all, with the date of each time when `dated`.
      def self.report(rows, count, io, dated: false)
        return if rows.empty?

        slowest = rows.max_by(count, &:seconds)
        io.puts format("\nThe %d slowest of %d tests, %.1f s of %.1f s in all:",
                       slowest.size, rows.size, slowest.sum(&:seconds), rows.sum(&:seconds))
        slowest.each { |row| io.puts format("%8.2f s  %s%s", row.seconds, row.name, dated ? "  (#{row.date})" : "") }

        groups = rows.group_by(&:group).map { |group, members| [group, members.size, members.sum(&:seconds)] }
        io.puts format("\nThe %d groups that took the most time:", [count, groups.size].min)
        groups.max_by(count) { |_, _, seconds| seconds }.each do |group, size, seconds|
          io.puts format("%8.1f s  %5d tests  %s", seconds, size, group)
        end
      end

      # Writes each result's time to this run's journal as it ends, and adds
      # the journal to the table at the end.
      class Reporter < Minitest::AbstractReporter
        def initialize(dir = DIR)
          super()
          @dir = dir
          @journal = nil
        end

        def start
          FileUtils.mkdir_p(@dir)
          Timings.merge(@dir)
          @date = Time.now.strftime("%Y-%m-%d")
          @journal = File.open(File.join(@dir, "times-#{Process.pid}.tsv"), "a")
          @journal.sync = true
        rescue SystemCallError
          @journal = nil
        end

        def record(result)
          @journal&.write(Timings.line(Timings.row(result, @date)))
        rescue SystemCallError
          nil
        end

        def report
          return unless @journal

          @journal.close
          Timings.merge(@dir, mine: Process.pid)
        end
      end
    end
  end
end

Minitest.register_plugin(Zr::Test::Timings)
