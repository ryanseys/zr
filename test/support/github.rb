# frozen_string_literal: true

require "minitest"

module Zr
  module Test
    # What a run tells GitHub Actions, when it runs there (GITHUB_ACTIONS):
    # an error annotation for each failure, at its test's line, and a
    # summary of the step (GITHUB_STEP_SUMMARY): the counts, then a table
    # of the failures, each with the first line of its message. The full
    # reports stay in the run's output and its log (Progress).
    module GitHub
      # The most failures that a run annotates and puts in its summary.
      MOST = 50

      def self.minitest_plugin_init(_options)
        Minitest.reporter << Reporter.new if ENV["GITHUB_ACTIONS"] == "true"
      end

      # A workflow command's data, with the characters that end it escaped.
      def self.escape(text) = text.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")

      # The test's file, relative to the checkout, and its line.
      def self.place(result)
        file, line = result.source_location
        [file.to_s.delete_prefix("#{File.expand_path("../..", __dir__)}/"), line]
      end

      # A diff's header lines, which say nothing of the failure.
      DIFF_HEADER = /\A(?:--- expected|\+\+\+ actual|@@ .* @@)\s*\z/

      # The test's name: its class and method.
      def self.name(result) = "#{result.klass}##{result.name}"

      # The first line of a failure's message that says something: for a
      # program test, it names the program; for a diff, it is the first
      # line that differs.
      def self.headline(result)
        result.failure.message.lines.map(&:strip).find { |line| !line.empty? && !line.match?(DIFF_HEADER) }.to_s[0, 300]
      end

      class Reporter < Minitest::AbstractReporter
        def initialize
          super
          @failed = []
          @counts = Hash.new(0)
          @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def record(result)
          kind = if result.skipped? then :skipped
                 elsif result.passed? then :passed
                 else :failed
                 end
          @counts[kind] += 1
          return unless kind == :failed

          @failed << result
          return if @failed.size > MOST

          file, line = GitHub.place(result)
          $stdout.puts "::error file=#{file},line=#{line},title=#{GitHub.escape(GitHub.name(result))}::#{GitHub.escape(GitHub.headline(result))}"
        end

        def report
          path = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
          return unless path

          File.write(path, summary, mode: "a")
        rescue SystemCallError => e
          warn "zr: no step summary: #{e.message}"
        end

        def passed? = true

        private

        def summary
          seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started
          what = %w[ZR_TARGET ZR_PROGRAMS ZR_TEST_SHARD].filter_map { |name| "#{name}=#{ENV[name]}" if ENV[name] }
          lines = ["### Tests#{" (#{what.join(", ")})" unless what.empty?}", "",
                   format("%d passed, %d failed, %d skipped in %.0f s", @counts[:passed], @counts[:failed], @counts[:skipped], seconds), ""]
          unless @failed.empty?
            lines << "| Test | Where | Message |" << "| --- | --- | --- |"
            @failed.first(MOST).each do |result|
              cell = ->(text) { text.gsub("|", "\\|") }
              lines << "| #{cell.(GitHub.name(result))} | #{GitHub.place(result).join(":")} | #{cell.(GitHub.headline(result))} |"
            end
            lines << "" << "#{@failed.size - MOST} more failures are in the log." if @failed.size > MOST
          end
          "#{lines.join("\n")}\n\n"
        end
      end
    end
  end
end

Minitest.register_plugin(Zr::Test::GitHub)
