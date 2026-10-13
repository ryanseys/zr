# frozen_string_literal: true

require "fileutils"
require "minitest"

module Zr
  module Test
    # The tests that failed, which `zr-dev test --failed` runs again. Each
    # line names one test: a test file and the line of the test
    # (`test/unit/cli_test.rb:12`), or `program <name>` for a program test.
    # A run takes off each test that it ran and that passed, and adds each
    # that failed; a test that it did not run keeps its line, as RSpec's
    # --only-failures keeps the status of each example.
    module LastFailures
      ROOT = File.expand_path("../..", __dir__)
      PATH = File.join(ROOT, "tmp", "zr-dev-test", "failed.txt")

      # The lines that the runs so far left, or none.
      def self.read(path = PATH) = File.file?(path) ? File.readlines(path, chomp: true).reject(&:empty?) : []

      def self.minitest_plugin_init(_options)
        Minitest.reporter << Reporter.new
      end

      # The line that names `result`'s test.
      def self.line(result)
        return "program #{result.name.delete_prefix("test_")}" if result.klass == "ProgramsTest"

        path, number = result.source_location
        "#{Pathname(path).expand_path.relative_path_from(Pathname(ROOT))}:#{number}"
      end

      class Reporter < Minitest::AbstractReporter
        def initialize(path = PATH)
          super()
          @path = path
          @ran = []
          @failed = []
        end

        def record(result)
          line = LastFailures.line(result)
          @ran << line
          @failed << line unless result.passed? || result.skipped?
        end

        def report
          lines = (LastFailures.read(@path) - @ran) | @failed
          FileUtils.mkdir_p(File.dirname(@path))
          File.write(@path, lines.map { |line| "#{line}\n" }.join)
        end
      end
    end
  end
end

Minitest.register_plugin(Zr::Test::LastFailures)
