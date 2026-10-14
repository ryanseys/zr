# frozen_string_literal: true

require "date"
require "fileutils"
require "minitest"
require_relative "scratch"

module Zr
  module Test
    # What the runs of the tests keep for later runs, in DIR.
    #
    # TABLE (`zr-dev test --slowest`) holds the time of each test, one
    # line each: its seconds, the date of its run, its group (its test
    # file, or a program test's directory below test/programs) and its
    # name (`Class#test_name`), separated by tabs, the slowest first. A run
    # writes each time to a journal of its own as the test ends, so a run
    # that is killed keeps the times so far. The end of the run adds its
    # journal to TABLE, and so does the start of a later run for a journal
    # whose run is gone. A test that ran again gets its new time; one that
    # did not keeps its old one, until its group is gone or it has not run
    # for KEEP_DAYS.
    #
    # FAILED (`zr-dev test --failed`) names the tests that failed, one per
    # line: a test file and the line of the test (`test/unit/cli_test.rb:12`),
    # or `program <name>` for a program test. A run takes off each test
    # that it ran and that passed, and adds each that failed; a test that
    # it did not run keeps its line, as RSpec's --only-failures does.
    module History
      ROOT = File.expand_path("../..", __dir__)
      # `ZR_TEST_TMP` moves these files: a suite that a test starts
      # (test/unit/fork_pool_test.rb) must not write over the run that
      # started it.
      TMP = ENV.fetch("ZR_TEST_TMP") { File.join(ROOT, "tmp") }
      DIR = File.join(TMP, "zr-dev-test")
      TABLE = File.join(DIR, "times.tsv")
      FAILED = File.join(DIR, "failed.txt")
      JOURNAL = /\Atimes-(\d+)\.tsv\z/
      KEEP_DAYS = 30

      Row = Struct.new(:seconds, :date, :group, :name)

      def self.minitest_plugin_init(_options)
        Minitest.reporter << Reporter.new
      end

      # `{ name => Row }` of the table at `path`, or none.
      def self.read(path = TABLE)
        return {} unless File.file?(path)

        File.foreach(path, chomp: true).each_with_object({}) do |line, rows|
          seconds, date, group, name = line.split("\t", 4)
          rows[name] = Row.new(Float(seconds), date, group, name) if name
        end
      end

      # The lines of the failure list at `path`, or none.
      def self.failed(path = FAILED) = File.file?(path) ? File.readlines(path, chomp: true).reject(&:empty?) : []

      # Adds each journal in `dir` to the table there and removes it: the
      # journal of `mine` (a pid), and each one whose run has ended.
      def self.merge(dir = DIR, mine: nil, root: ROOT)
        table = File.join(dir, File.basename(TABLE))
        journals = Dir.children(dir).filter_map do |name|
          pid = name[JOURNAL, 1]&.to_i
          File.join(dir, name) if pid && (pid == mine || !Scratch.alive?(pid))
        end
        return if journals.empty?

        rows = read(table)
        journals.sort_by { |path| File.mtime(path) }.each do |path|
          rows.merge!(read(path))
          File.delete(path)
        end
        write(current(rows.values, root), table)
      rescue SystemCallError
        nil
      end

      # The rows of `rows` whose group is still below `root` and that ran
      # in the last KEEP_DAYS: one stat for each group.
      def self.current(rows, root = ROOT, today: Date.today)
        oldest = (today - KEEP_DAYS).iso8601
        there = Hash.new { |seen, group| seen[group] = File.exist?(File.join(root, group)) }
        rows.select { |row| row.date >= oldest && there[row.group] }
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

      # The line of FAILED that names `result`'s test.
      def self.failed_line(result)
        return "program #{result.name.delete_prefix("test_")}" if result.klass == "ProgramsTest"

        path, number = result.source_location
        "#{Pathname(path).expand_path.relative_path_from(Pathname(ROOT))}:#{number}"
      end

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

      # Writes each result's time to this run's journal as it ends. At the
      # end, it adds the journal to the table and writes the failure list.
      class Reporter < Minitest::AbstractReporter
        def initialize(dir = DIR, root: ROOT)
          super()
          @dir = dir
          @root = root
          @journal = nil
          @ran = []
          @failed = []
        end

        def start
          FileUtils.mkdir_p(@dir)
          History.merge(@dir, root: @root)
          @date = Date.today.iso8601
          @journal = File.open(File.join(@dir, "times-#{Process.pid}.tsv"), "a")
          @journal.sync = true
        rescue SystemCallError
          @journal = nil
        end

        def record(result)
          line = History.failed_line(result)
          @ran << line
          @failed << line unless result.passed? || result.skipped?
          @journal&.write(History.line(History.row(result, @date)))
        rescue SystemCallError
          nil
        end

        def report
          failures = File.join(@dir, File.basename(FAILED))
          File.write(failures, ((History.failed(failures) - @ran) | @failed).map { |line| "#{line}\n" }.join)
          return unless @journal

          @journal.close
          History.merge(@dir, mine: Process.pid, root: @root)
        rescue SystemCallError
          nil
        end
      end
    end
  end
end

Minitest.register_plugin(Zr::Test::History)
