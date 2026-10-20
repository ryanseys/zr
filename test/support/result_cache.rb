# frozen_string_literal: true

require_relative "flag"
require "digest"
require_relative "../../lib/zr/cache/store"
require_relative "../../tool/lib/zr/dev/process"
require_relative "../../tool/lib/zr/dev/reach"

module Zr
  module Test
    # The program tests that passed, so that a later run with the same
    # inputs does not build and run them again (or walk them, with
    # `ZR_TEST_HOST=1`). An entry is a key in the store (kind `result`)
    # that holds no value: its key is a digest of everything a run of the
    # test reads, so any change to them misses.
    #
    # The key holds the test's program and the files beside it, its
    # baseline line, the ruby, each `ZR_*` and `RUBY*` variable but the
    # ones that change no result (`IGNORED`), `WASMTIME` and
    # `OPENSSL_DIR`, and the state of the paths that a run reads (`READ`):
    # the blob of each file of them that git tracks, and the bytes of each
    # one that differs from it or that git does not track yet. So a change
    # to zr, to the pinned ruby or gems, or to a file on the program
    # tests' load path misses, and a change to the docs, another test tier
    # or another tool does not. A copy that is no git checkout stamps the
    # same paths by size and mtime. `ZR_TEST_FRESH=1`
    # (`zr-dev test --no-cache`) runs every test.
    class ResultCache
      ROOT = File.expand_path("../..", __dir__)
      # A pass is an empty entry of the store kind `result`.
      Zr::Cache::Store.register(Zr::Cache::Store::Kind.new(:result, :raw, "", nil))
      # The test and tool files that a program test loads: each file that
      # test/programs_test.rb reaches by a literal require
      # (`Dev::Reach::LoadGraph`), outside lib and vendor, which READ holds
      # whole.
      HARNESS = Zr::Dev::Reach::LoadGraph.new.closure(File.join(ROOT, "test/programs_test.rb"))
                                         .map { |path| path.delete_prefix("#{ROOT}/") }
                                         .reject { |rel| rel.start_with?("lib/", "vendor/") }.sort.freeze
      # What a run reads, below the root: zr itself, the pinned ruby, the
      # locked gems, the baselines, and HARNESS.
      READ = ["lib", "vendor", "exe", ".ruby-version", "Gemfile.lock", "test/baselines", *HARNESS].freeze
      # The variables that change no result: they pick, report or speed up
      # tests, or bound the caches.
      IGNORED = %w[ZR_PROGRAMS ZR_TEST_FRESH ZR_TEST_FAIL_FAST ZR_TEST_TMP ZR_MINITEST_RUN ZR_TEST_ALL ZR_TEST_BUILT ZR_TEST_BINARIES
                   ZR_TEST_BINARIES_GB ZR_TEST_RECYCLE_MB ZR_JOBS ZR_TIMING ZR_CACHE_MAX_GB ZR_BLESS].freeze
      # The variables outside ZR_ and RUBY that change a run.
      READ_ENV = %w[WASMTIME OPENSSL_DIR].freeze

      def self.enabled? = !Zr::Test.flag?("ZR_TEST_FRESH")

      # `root` is the checkout whose state the key holds.
      def initialize(root: ROOT)
        @root = root
        @tree = tree_digest
      end

      # The digest of the paths that a run reads (READ).
      attr_reader :tree

      # `[[name, value]]` of each variable that can change a run.
      def self.variables
        ENV.select { |name, _| name.start_with?("ZR_", "RUBY") ? !IGNORED.include?(name) : READ_ENV.include?(name) }.sort
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
          @tree, RUBY_DESCRIPTION, self.class.variables.inspect,
          test.rel, test.source, baseline.to_s,
          *beside.flat_map { |path| [File.basename(path), File.binread(path)] },
          *files.flat_map { |name| [name, file_bytes(File.join(test.files, name))] }
        )
      end

      def file_bytes(path) = File.file?(path) ? File.binread(path) : ""

      def tree_digest
        index = Dev.git("ls-files", "-s", "--", *READ, dir: @root)
        return stamp_digest if index.nil?

        digest = Digest::SHA256.new << index
        changed = Dev.git("ls-files", "-m", "-o", "--exclude-standard", "--", *READ, dir: @root).to_s
        changed.lines(chomp: true).uniq.sort.each do |rel|
          digest << rel << "\0" << file_bytes(File.join(@root, rel)) << "\0"
        end
        digest.hexdigest
      end

      def stamp_digest
        digest = Digest::SHA256.new
        READ.flat_map { |rel| [File.join(@root, rel), *Dir.glob("#{@root}/#{rel}/**/*")] }.sort.each do |path|
          next unless File.file?(path)

          stat = File.stat(path)
          digest << path << "\0" << stat.size.to_s << "\0" << stat.mtime.to_r.to_s << "\0"
        end
        digest.hexdigest
      end
    end
  end
end
