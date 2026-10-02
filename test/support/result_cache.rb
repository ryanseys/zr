# frozen_string_literal: true

require "digest"
require_relative "../../lib/zr/cache/store"

module Zr
  module Test
    # The host program tests that passed, so that a later run with the
    # same inputs does not walk them again (`ZR_TEST_HOST=1`, where one
    # test takes seconds). An entry is a key in the store (kind `result`)
    # that holds no value: its key is a digest of everything a host run of
    # the test reads, so any change to them misses.
    #
    # The key holds the test's program and the files beside it, its
    # baseline line, the ruby, the collector's switches (`ZR_GC_*`), and
    # a stamp (size and mtime) of each file below lib, vendor, gems and
    # test/support, which is where the kernel, the core, the walker and
    # the libraries a program requires are. `ZR_TEST_FRESH=1` runs every
    # test.
    class ResultCache
      ROOT = File.expand_path("../..", __dir__)
      TREES = %w[lib vendor gems test/support].freeze

      def self.enabled? = ENV["ZR_TEST_FRESH"] != "1"

      def initialize
        @tree = tree_digest
      end

      def passed?(test, baseline) = !Cache::Store.read(:result, key(test, baseline)).nil?

      # Records the pass, unless a source of zr changed while the run went
      # on: then the pass may be of the old code.
      def pass!(test, baseline)
        Cache::Store.write(:result, key(test, baseline), "")
      rescue SourceChanged
        nil
      end

      private

      def key(test, baseline)
        beside = Dir.glob("#{test.path}.*").sort.reject { |path| File.directory?(path) }
        files = test.files ? Dir.glob("**/*", File::FNM_DOTMATCH, base: test.files).sort : []
        Cache::Store.key(
          @tree, RUBY_DESCRIPTION, ENV.select { |name, _| name.start_with?("ZR_GC_") }.sort.inspect,
          test.rel, test.source, baseline.to_s,
          *beside.flat_map { |path| [File.basename(path), File.binread(path)] },
          *files.flat_map { |name| [name, file_bytes(File.join(test.files, name))] }
        )
      end

      def file_bytes(path) = File.file?(path) ? File.binread(path) : ""

      def tree_digest
        digest = Digest::SHA256.new
        TREES.flat_map { |dir| Dir.glob("#{ROOT}/#{dir}/**/*") }.sort.each do |path|
          next unless File.file?(path)

          stat = File.stat(path)
          digest << path << "\0" << stat.size.to_s << "\0" << stat.mtime.to_r.to_s << "\0"
        end
        digest.hexdigest
      end
    end
  end
end
