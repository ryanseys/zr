# frozen_string_literal: true

require "fileutils"

module Zr
  module Test
    # The files of one test run, under one name in log/minitest/: its
    # output (`.log`, which bin/minitest copies there as the run goes),
    # its status (`.progress.log`), and the full report of each failure
    # as it happens (`.failures.log`). So a run that stops early keeps
    # all that it did until then. `latest.log` and the others name the
    # newest run's files, and the KEEP newest runs stay.
    #
    # `ZR_TEST_TMP` moves them: a suite that a test starts
    # (test/unit/fork_pool_test.rb) must not write over the run that
    # started it.
    module RunFiles
      DIR = ENV.fetch("ZR_TEST_TMP") { File.expand_path("../../log/minitest", __dir__) }
      KEEP = 30

      # The name of this run's files, less the suffix: the one that
      # bin/minitest gave the run (`ZR_MINITEST_RUN`) when it is in DIR,
      # else a new one.
      BASE = ENV["ZR_MINITEST_RUN"]&.then { |run| run if File.dirname(run) == DIR } ||
             File.join(DIR, "#{Time.now.strftime("%Y%m%d-%H%M%S")}-#{Process.pid}")

      def self.base = BASE

      def self.path(suffix) = "#{base}.#{suffix}"

      # Makes `latest.<suffix>` name this run's file, and deletes the
      # files of the runs older than the KEEP newest.
      def self.start(suffix)
        FileUtils.mkdir_p(DIR)
        FileUtils.ln_sf(File.basename(path(suffix)), File.join(DIR, "latest.#{suffix}"))
        runs = Dir[File.join(DIR, "2*")].map { |file| file[/\A.*\d{8}-\d{6}-\d+/] }.uniq.sort
        runs.first([runs.size - KEEP, 0].max).each { |old| Dir["#{old}.*"].each { |file| File.delete(file) } }
      rescue SystemCallError
        nil
      end
    end
  end
end
